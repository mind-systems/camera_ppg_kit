# Plan Review: flutter_ppg finger-video harness

**Plan:** `.ai-factory/plans/02-flutter-ppg-finger-video-harness.md`
**Files cross-checked:** 6 (existing `example/lib/auto_detect/*`, `flutter_ppg` 0.2.4 source, ARCHITECTURE/ROADMAP/rules)
**Risk Level:** 🟢 Low

## Summary

This is a well-grounded plan. Every external API fact it asserts was verified against the
installed `flutter_ppg` 0.2.4 package, every file path it references exists or is correctly
placed, and the design faithfully reuses the established camera-open / ordered-teardown pattern
from `coverage_detector.dart`. The constraints (example-only, raw passthrough, slow-rebuild UI,
real-device-only) are exactly the right ones and match note 02 and the ROADMAP Phase 2 milestone.

The findings below are minor correctness gaps the implementer must handle — none change the
architecture or sequencing.

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** PASS. All new code goes under `example/lib/` (playground),
  not `lib/src/`. The plan explicitly forbids touching `lib/src/`, honoring the "barrel is the
  contract" boundary and the no-acceptance-policy / no-isolate deferral. No dependency-rule
  violation.
- **Rules (`rules/base.md`):** PASS. File names are `snake_case.dart`; no new dependencies
  (`camera` + `flutter_ppg` already in `example/pubspec.yaml`); logging routes through the existing
  `ppgLog` helper rather than the app facade.
- **Roadmap (`ROADMAP.md`):** PASS. Directly fulfills the Phase 2 "flutter_ppg finger-video harness"
  task (line 16), correctly scoped as the raw stream-inspector panel feeding the device-support
  matrix / go-no-go. Good milestone linkage.

## Verified API facts (flutter_ppg 0.2.4)

All confirmed against `~/.pub-cache/hosted/pub.dev/flutter_ppg-0.2.4`:

- `FlutterPPGService.processImageStream(Stream<CameraImage>) → Stream<PPGSignal>` exists
  (`flutter_ppg_service.dart:155`), and `dispose()` exists (`:113`).
- Every `PPGSignal` field the plan renders is real: `rawIntensity`, `filteredIntensity`,
  `rrIntervals`, `quality`, `timestamp`, `snr`, `frameRate`, `isFPSStable`, `driftRate`, `sdrr`,
  `isSDRRAcceptable`, `rejectionRatio`, `rejectedIntervalCount` (`ppg_signal.dart`).
- There is indeed **no `fingerPresence` field** on `PPGSignal` — the plan's decision to derive it
  from `rawIntensity` vs `PPGConfig.fingerPresenceMin/Max` is correct.
- `PPGConfig.fingerPresenceMin = 30.0`, `fingerPresenceMax = 250.0` (defaults) — so the Task 1
  helper with `{PPGConfig config = const PPGConfig()}` reproduces `coverage_detector.dart`'s inline
  `covered()` exactly (`raw > min && raw < max`, strict bounds). Behavior-identical refactor confirmed.
- `SignalQuality` enum is `poor/fair/good` (`ppg_signal.dart:2`) — matches the SQI tally design.

## Findings (non-blocking)

### 1. Guard empty `rrIntervals` before deriving BPM (WARN — correctness)
Task 4 specifies "latest RR interval(s) from `rrIntervals`" and "derived BPM = `60000 / lastRrMs`".
`flutter_ppg` documents `rrIntervals` as **empty when insufficient peaks are detected or quality is
poor** (`ppg_signal.dart:32`). Two runtime hazards the plan doesn't mention:
- `rrIntervals.last` throws `StateError` on an empty list.
- `60000 / 0` (or a near-zero RR) yields `Infinity`/garbage.

The implementer must render a placeholder (e.g. `—`) when `rrIntervals.isEmpty`, and only compute
BPM from a positive last interval. Worth stating in the task so it isn't missed during a "raw
passthrough" mindset.

### 2. Make Timer + signals-subscription teardown explicit in `dispose` (WARN — lifecycle)
Task 4 drives the UI from a `Timer.periodic` and updates `_latest`/tally from a `signals` listener.
The plan says `dispose` calls `runner.stop()`, but does not explicitly require:
- cancelling the `Timer.periodic` (otherwise a tick fires `setState` after dispose → "setState
  called after dispose" exception), and
- cancelling the screen's own `StreamSubscription` to `runner.signals`.

`runner.stop()` tears down the camera/service but cannot cancel the UI's timer or its subscription.
Both must be cancelled in `StreamInspectorScreen.dispose` before/alongside `stop()`. Add this to the
task.

### 3. Confirm the broadcast wiring keeps the `async*` source alive (note — implementation)
`processImageStream` is an `async*` generator → a **single-subscription** stream. The plan correctly
calls for a **broadcast** `signals` getter, which is necessary because two consumers exist: the UI
listener *and* the internal `FpsMeter` feed ("fed one `record(...)` per emitted signal"). The
implementer should convert via a broadcast `StreamController` (or `asBroadcastStream()`) **and**
ensure the internal `FpsMeter`-feeding subscription is attached in `start()` so frames flow even
before the UI subscribes. This matches the plan's intent; just flagging it so the single-vs-broadcast
nuance isn't lost.

### 4. `'monospace'` font family on iOS (INFO — cosmetic, pre-existing)
Task 4 reuses the `fontFamily: 'monospace'` styling already used in `auto_detect_screen.dart`.
Flutter maps `'monospace'` reliably on Android but falls back to a default on iOS. This is a
pre-existing example-app convention, not introduced here, and purely cosmetic — no action required,
noted only for completeness.

## Positive notes

- The plan correctly recognizes that the auto-detect round-trip **fully tears down** the camera
  before returning success (`coverage_detector.dart` calls `_tearDown` then returns), so navigating
  to the inspector with `outcome.lockedCamera` and re-opening there preserves the "one camera session
  at a time" invariant. The single-session reasoning in Task 5 is accurate.
- Extracting `isFingerPresent` (Task 1) and `FpsMeter` (Task 2) as pure, Flutter-free helpers is the
  right call — reusable into `lib/src/processing/` later and trivially testable.
- Measuring sustained FPS independently of `PPGSignal.frameRate` (which is flutter_ppg's own
  nominal/detected estimate) is exactly what note 02 asks for and avoids conflating the two numbers.
- Throttling rebuilds via a ~3 Hz timer rather than per-frame `setState` directly addresses the
  FPS-starvation guard from DESCRIPTION/note 02 — the plan understands *why* the constraint exists.
- The teardown order is reused verbatim from the proven `coverage_detector._tearDown`, including the
  `?.`/`isClosed` guards against late frame callbacks.
- Commit plan splits cleanly along the data-path / UI boundary.

## Verdict

The plan is architecturally sound, sequenced correctly, and free of wrong-API or wrong-path
assumptions. The three WARN/INFO items are implementation-detail safeguards (empty-list/zero guards,
explicit timer+subscription cancellation, broadcast keep-alive) rather than structural problems —
fold them into Tasks 4 (and note the broadcast detail in Task 3) and proceed.
