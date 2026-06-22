# Plan Review 2: flutter_ppg finger-video harness

**Plan:** `.ai-factory/plans/02-flutter-ppg-finger-video-harness.md`
**Files cross-checked:** `example/lib/auto_detect/{coverage_detector,camera_probe,auto_detect_result,auto_detect_screen,log}.dart`, `example/pubspec.yaml`, `flutter_ppg` 0.2.4 source (`ppg_signal.dart`, `ppg_config.dart`, `flutter_ppg_service.dart`).
**Risk Level:** 🟢 Low

## Summary

The plan is solid and ready to implement. This second pass independently re-verified every
external API fact, every referenced file path, and the reuse claims against the actual code —
all hold. The architecture (example-only, raw passthrough, slow-rebuild UI, real-device-only,
sustained-FPS measured separately from `PPGSignal.frameRate`) is correct and matches notes
01/02 and the ROADMAP Phase 2 milestone.

Round 1's three WARN/INFO items are still **not folded into the plan text** (Task 4 still says
"derived BPM = `60000 / lastRrMs`" with no empty-list guard; `dispose` is still described only as
`stop()` with no explicit Timer/subscription cancellation). They remain non-blocking
implementation safeguards — the implementer has both reviews — but I restate them below so they
are not lost, plus a few incremental notes specific to this pass.

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** PASS. All new files live under `example/lib/`
  (`common/`, `inspector/`); nothing touches `lib/src/`. The pure helpers (Task 1 `isFingerPresent`,
  Task 2 `FpsMeter`) are Flutter-free and migratable into `lib/src/processing/` later — consistent
  with the kit's target shape. No dependency-rule violation.
- **Rules (`rules/`):** PASS. `snake_case.dart` filenames; no new dependencies (`camera ^0.12.0+1`
  + `flutter_ppg ^0.2.4` already in `example/pubspec.yaml`, confirmed); logging routes through the
  existing `ppgLog` helper.
- **Roadmap (`ROADMAP.md`):** PASS. Fulfills the Phase 2 "flutter_ppg finger-video harness" task as
  the raw stream-inspector feeding the device-support / go-no-go decision. Good linkage.

## Independently re-verified API facts (flutter_ppg 0.2.4)

- `FlutterPPGService.processImageStream(Stream<CameraImage>) → Stream<PPGSignal>` is an `async*`
  generator → **single-subscription** (`flutter_ppg_service.dart:155`). `dispose()` exists (`:113`).
  The plan's broadcast-`signals` decision is therefore correct and necessary.
- Every `PPGSignal` field the plan renders is real (`ppg_signal.dart`): `rawIntensity`,
  `filteredIntensity`, `rrIntervals` (`List<double>`), `quality` (`SignalQuality`), `timestamp`,
  `snr`, `frameRate`, `isFPSStable`, `driftRate`, `sdrr`, `isSDRRAcceptable`, `rejectionRatio`,
  `rejectedIntervalCount`. There is **no `fingerPresence` field** — deriving it from `rawIntensity`
  is the right call.
- `SignalQuality` enum is exactly `poor/fair/good` (`ppg_signal.dart:1-14`) — matches the SQI tally.
- `PPGConfig.fingerPresenceMin = 30.0`, `fingerPresenceMax = 250.0` (`ppg_config.dart:64-65`), with
  `assert(fingerPresenceMax > fingerPresenceMin)`. The Task 1 helper signature
  `isFingerPresent(double, {PPGConfig config = const PPGConfig()})` reproduces
  `coverage_detector.dart`'s inline `covered()` exactly (`raw > min && raw < max`, strict bounds).
  Behavior-identical refactor confirmed.
- `CoverageOutcome.isSuccess` (`auto_detect_result.dart:73`) and `lockedCamera` (`:69`, nullable)
  exist — Task 5's `outcome.isSuccess` / `outcome.lockedCamera!` usage is correct, and the success
  banner it hooks into (`auto_detect_screen.dart:235` `_successBanner`) is where the new affordance
  belongs.

## Findings

### 1. Empty `rrIntervals` / zero-division guard — still unaddressed in plan text (WARN — correctness)
`rrIntervals` is documented empty "if insufficient peaks are detected or signal quality is poor"
(`ppg_signal.dart:32`). Task 4 must render a placeholder when `rrIntervals.isEmpty` and compute
`60000 / lastRrMs` only from a positive last interval — otherwise `.last` throws `StateError` and a
zero/near-zero interval yields `Infinity`. Carry-over from review 1, not yet in the plan.

### 2. Timer + signals-subscription teardown not explicit in `dispose` (WARN — lifecycle)
`runner.stop()` tears down the camera/service but cannot cancel the screen's own `Timer.periodic`
or its `StreamSubscription` to `runner.signals`. Both must be cancelled in
`StreamInspectorScreen.dispose` (alongside `stop()`), or a post-dispose tick calls `setState` →
"setState called after dispose". Carry-over from review 1, not yet in the plan.

### 3. Broadcast keep-alive: FpsMeter feed must subscribe in `start()` (WARN — correctness)
Because `processImageStream` is single-subscription, the broadcast wrapper only pulls frames while
≥1 listener is attached. The internal `FpsMeter`-feeding subscription must be attached in `start()`
so frames flow (and `sustainedFps` updates) even before the UI subscribes, and so the UI listener
and the meter share the same broadcast source rather than each trying to listen to the underlying
single-subscription stream. The plan's intent matches this; just make the internal subscription
explicit in Task 3 (and cancel it in `stop()`'s ordered teardown).

### 4. `start()` is unawaited in `initState` — guard the async open path (INFO — robustness)
`initState` cannot be `async`, so `MeasurementRunner.start()` is fire-and-forget. This is fine for
the playground, but reinforces finding #2 of Task 3: camera-open failures must be caught inside
`start()` and routed to `ppgLog` (leaving `signals` idle), never thrown — otherwise an unhandled
async error escapes with no UI frame to catch it. The plan already states this; flagging that the
unawaited-in-`initState` shape makes it mandatory, not optional.

### 5. `'monospace'` on iOS (INFO — cosmetic, pre-existing)
Reusing `fontFamily: 'monospace'` (as in `auto_detect_screen.dart`) falls back to a default font on
iOS. Pre-existing example convention, purely cosmetic — no action.

## Positive notes

- Single-camera-session invariant is sound: `detectCoveredCamera` runs `_tearDown` before returning
  success (`coverage_detector.dart:111-120`), so navigating to the inspector and re-opening there
  never holds two controllers at once. Task 5's reasoning is accurate.
- The teardown order the plan reuses (`_tearDown`, lines 178-209: stop stream → cancel sub → dispose
  service → close controller → torch off → dispose controller, with `?.`/`isStreamingImages`/
  `isInitialized` guards) is the proven pattern and correctly cited.
- Measuring sustained FPS via a wall-clock rolling window, independent of flutter_ppg's nominal
  `frameRate`, is exactly note 02's requirement and avoids conflating the two numbers.
- The ~3 Hz rebuild throttle (decoupling `setState` from frame arrival) directly addresses the
  FPS-starvation guard — the plan understands *why* the constraint exists, not just that it does.
- Extracting `isFingerPresent` and `FpsMeter` as pure helpers is the right reuse seam for later
  `lib/src/` phases. Commit plan splits cleanly along the data-path / UI boundary.

## Verdict

Architecturally sound, correctly sequenced, no wrong-API or wrong-path assumptions. The five items
are implementation-detail safeguards (empty-list/zero guard, explicit Timer+subscription
cancellation, broadcast keep-alive, async-open error containment, cosmetic font) — none structural.
Fold findings 1–3 into Tasks 3/4 during implementation and proceed.

PLAN_REVIEW_PASS
